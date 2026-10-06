class_name StatusEvents
extends RefCounted

## Typed event contract for status application and refusal (ADR 0902, P5/P13).
##
## The observation half of the seam: a consumer subscribes without the `status`
## module naming it, and the RESISTED LOG is the after-the-fact read model — every
## entry carries the closed refusal reason that produced it, because a status that
## vanished for an unnamed reason is the invisible resistance ADR 0086 refuses.
##
## **Every signal here announces what already happened.** None is a request and none
## may be vetoed: by the time `status_applied` fires the effect is on the actor and
## its modifiers are applied, and by the time `status_resisted` fires the application
## had already been refused. Shaped like `npc_events.gd` and `quest_events.gd`:
## primitives only, one fact per signal, and the id vocabulary is the module's own.
##
## ## Why the bus lives HERE and not behind `StatusApi`
##
## The spine's S12 stage applies a status through `StatusApply._written` and
## `Actor.add_status` WITHOUT naming the `status` module — `combat_engine` declares
## `contracts` and `core` and not `status/`, and that boundary is the point of the
## stage. A bus held on the status facade would be unreachable from the module that
## owns the spine's apply site, which is how a declared signal becomes a signal nobody
## emits (the `npc_events.gd` note, verbatim). `contracts/` is the leaf layer, so a
## static here is a legal home for a shared instance and no dependency is invented.

## A status landed on `host_id`. `instance_id` is the handle `StatusRegistry` minted
## and `grant_id` is the application's own handle (ADR 0902, P5), empty when the
## caller brought none.
signal status_applied(
	host_id: StringName, status_id: StringName, instance_id: int, grant_id: StringName
)

## An application was refused before it landed. `reason` is the closed refusal
## vocabulary entry the refusing layer named; `detail` names its subject when one
## exists (the immunity tag that refused, the actor's own inner reason) and is empty
## otherwise — never a formatted sentence.
signal status_resisted(
	host_id: StringName, status_id: StringName, reason: StringName, detail: StringName
)

## How many refusals the log keeps (ADR 0902, P13). A read model for a screen and a
## test rather than a history: the oldest entry is dropped once the cap is reached,
## and the bound is a constant, so no caller can grow it by refusing harder.
const RESISTED_LOG_CAP := 32

static var _shared: StatusEvents = null
var _resisted: Array[Dictionary] = []


## The single bus every status publisher and subscriber shares. Stable across calls,
## so a subscriber that connected once is still connected the next time it asks.
static func shared() -> StatusEvents:
	if _shared == null:
		_shared = StatusEvents.new()
	return _shared


## Emit one APPLIED fact. A helper rather than a bare `.emit(` so both apply doors
## announce in one spelling.
static func note_applied(
	host_id: StringName, status_id: StringName, instance_id: int, grant_id: StringName = &""
) -> void:
	shared().status_applied.emit(host_id, status_id, instance_id, grant_id)


## Emit one REFUSED fact and remember it. The entry is appended BEFORE the emit, so a
## subscriber that re-reads the log from inside its own handler sees the fact it was
## just told about.
static func note_resisted(
	host_id: StringName,
	status_id: StringName,
	reason: StringName,
	detail: StringName = &""
) -> void:
	var bus := shared()
	bus._resisted.append(
		{
			"host": String(host_id),
			"id": String(status_id),
			"reason": String(reason),
			"detail": String(detail),
		}
	)
	# Bounded as each entry lands — ONE `if`, never a `while`: the log is a window,
	# and this is the loop shape INC-0002 cannot exist in.
	if bus._resisted.size() > RESISTED_LOG_CAP:
		bus._resisted.pop_front()
	bus.status_resisted.emit(host_id, status_id, reason, detail)


## The refusals newest-last, as primitives-only copies: a caller cannot reach into
## the log and rewrite what happened.
func resisted_log() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for entry in _resisted:
		copy.append(entry.duplicate())
	return copy


## Drop the log. For tests, and for a caller that closes the screen reading it.
func clear_log() -> void:
	_resisted.clear()
