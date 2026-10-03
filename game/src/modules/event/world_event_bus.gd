class_name WorldEventBus
extends RefCounted

## The event module's announcement surface — the instance of the EXISTING
## `WorldEvents` contract (`src/contracts/world_events.gd`), which was declared by
## ADR 0019 and had no emitter and no listener at all.
##
## ## The bus is the SAME OBJECT every time, so a listener survives
##
## [method EventBus.instance] is process-wide and lazily built, exactly as
## `NationProjection.events()` and `DestinyProjection.events()` are. A bus handed out
## fresh per call would connect a listener that is then thrown away, and
## "a signal contract with no emitter" would become "a signal contract with an
## emitter nobody is connected to" — the same defect wearing a bus.
##
## ## SIGNALS ANNOUNCE, NEVER REQUEST (ADR 0093)
##
## Every emit below is downstream of a decision this module has already made and
## already persisted. A consumer observes; it never asks this module to do something
## and never holds a reference that would let it reach back in. Four of the nine
## declared `WorldEvents` signals fire here, at the four moments the director
## actually owns:
##
##   `world_conflict_triggered` — an event declared a war (a `sect_war` opening)
##   `world_conflict_resolved`  — a declared standoff closed through `NationApi`
##   `world_evolved`            — an event moved from one stage to the next
##   `world_upkeep_paid`        — a stage's price was settled against world stability
##
## The remaining five (`world_created`, `world_stability_changed`, `world_law_added`,
## `world_inhabitant_added`, `world_merged`) describe `actor.world`, the
## Transcendent-tier ability state in `core/world_creation.gd`. This module owns no
## such state and emits none of them — an emitter that fired them with invented
## values would make the contract a lie.

static var bus: WorldEventBus = null

## The one live bus. Process-wide for the reason on the class.
static var shared: WorldEvents = null


static func instance() -> WorldEvents:
	if shared == null:
		shared = WorldEvents.new()
	return shared


## Drop the bus so a test suite can re-listen from scratch. The game never needs it,
## because a bus has no state beyond its own connection list.
static func reset() -> void:
	shared = null
	bus = null


## An event opened, and the world it is happening in is under strain. This is the
## declaration itself — `begin` has already refused `unknown_event` /
## `trigger_unmet` / `wrong_location` and already applied the opening beats before
## anything is announced, so a listener hears a fact rather than a request.
static func conflict_triggered(actor_id: String, event_id: StringName, severity: float) -> void:
	instance().world_conflict_triggered.emit(actor_id, StringName(event_id), severity)


## A standoff this module declared through `NationApi.declare_war` has closed. The
## tally and the declared prize were `nation`'s to pay; this announces the fact.
static func conflict_resolved(
	actor_id: String, conflict_id: StringName, outcome: StringName
) -> void:
	instance().world_conflict_resolved.emit(actor_id, StringName(conflict_id), StringName(outcome))


## An event moved from one stage to the next under an explicit period count.
static func evolved(actor_id: String, old_stage: StringName, new_stage: StringName) -> void:
	instance().world_evolved.emit(actor_id, StringName(old_stage), StringName(new_stage))


## A stage's price was settled against world stability. `amount` is what the stage
## was authored to cost and `upkeep_rate` is what one period of that stage carries —
## both read from the def, never computed here.
static func upkeep_paid(actor_id: String, amount: float, upkeep_rate: float) -> void:
	instance().world_upkeep_paid.emit(actor_id, amount, upkeep_rate)
