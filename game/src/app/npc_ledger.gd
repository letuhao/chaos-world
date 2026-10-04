class_name NpcLedger
extends RefCounted

## The composition root's SUBSCRIBER to the npc event contract (ADR 0093, BL-0628).
##
## ## Why this file exists
##
## `contracts/npc_events.gd` declares seven signals, `npc/api.gd` and `social/api.gd`
## emit several of them, and **nothing in the tree connected to any of them**. ADR 0093
## line 21 promises "a subscriber connects from its own boot function, which `app/`
## calls" — but the promise had no subscriber, so the contract was a declaration
## nothing observed: exactly the "a signal nobody emits" state the contract's own
## docstring calls out. This file is the first real one, and `NpcBoot._install_event_seams`
## is the boot function that connects it.
##
## ## Why it is a `RefCounted` in `app/` and not a `Node` autoload
##
## `BeatDirector`, `WorldPulse` and `StatusLoop` all took this shape first: wiring, not
## rules, no clock, not an autoload, no `_process`. ADR 0093 accepts one cost of a
## signal bus — "an event that fires before a subscriber connects is lost" — and says
## so rather than leaving it to be discovered. That cost is only honest because the
## connect happens at BOOT, in the same function that installs the constructor, so
## nothing can advance a stage before this ledger is listening.
##
## ## It is an AUDIT TRAIL, and it is not persisted
##
## **A count and a bounded list, never a ledger a save round-trips.** The roster in
## `module_data` is the truth about who an npc is (ADR 0092); this file answers a
## different question — *what did the composition root observe, and in what order* —
## which is a log, and a log in `app/` that grew without limit is the stateful-system
## shape `tools/arch/rules.py` rejects. Hence [constant MAX_ROWS]: the oldest row is
## DROPPED at the bound, so the memory is a named constant rather than a growth curve.
##
## It holds no `Actor`, reads no `module_data` and writes none, so it adds no
## `persistence` signal to `app/` and never trips the app-state check.
##
## ## Primitives only, one fact per row (ADR 0093)
##
## Rows are `{npc_id, stage_id, source}` — all strings. `source` is kept because
## ADR 0093 makes it the way a consumer filters its own effects: a world event that
## moved an npc is distinguishable from a direct `advance_stage` without re-deriving it.

## The most rows the trail keeps. A save is a roster; this is a log, and a log that
## grew with every stage advance for the length of a session would be the unbounded
## table the composition root is not allowed to hold. The oldest row is dropped first.
const MAX_ROWS := 64

## Every `stage_advanced` this process has observed, oldest first.
##
## A `static var` because the bus is process-wide (`NpcEvents.shared()`) and a
## per-instance sink would need every owner to keep it alive to be worth connecting.
## `rules.py` excludes `static var` from the app-state heuristics by construction:
## this is process-wide memoisation, the same shape `recipe_catalog.gd` caches a
## directory walk in.
static var _rows: Array[Dictionary] = []


## The subscriber ADR 0093 names. Connected by `NpcBoot.install`; the exact static
## Callable, so `is_connected` can recognise it across boots and not connect twice.
static func advanced(npc_id: String, stage_id: StringName, source: String) -> void:
	var row := {"npc_id": npc_id, "stage_id": String(stage_id), "source": source}
	if _rows.size() >= MAX_ROWS:
		_rows.remove_at(0)
	_rows.append(row)


## The trail, newest first — the order a panel or a probe reads it in. Copied, so a
## caller cannot reach in and rewrite history.
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in range(_rows.size() - 1, -1, -1):
		out.append((_rows[index] as Dictionary).duplicate())
	return out


## How many advances have been observed, capped at [constant MAX_ROWS].
static func count() -> int:
	return _rows.size()


## The most recent row, or `{}` when nothing has advanced yet — the same empty-shape
## answer `NpcApi.summary` gives for an npc it does not ship.
static func last() -> Dictionary:
	if _rows.is_empty():
		return {}
	return (_rows[_rows.size() - 1] as Dictionary).duplicate()


## Forget the trail. Only a test harness calls this: `NpcEvents.shared()` is
## process-wide and a suite that advanced an elder would otherwise leave a row behind
## for whichever npc suite runs next and read a count that is not its own.
static func reset() -> void:
	_rows.clear()
