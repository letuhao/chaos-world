class_name ConflictEvents
extends RefCounted

## Signal contract for the `conflict` module (ADR 0085, ADR 0245, ADR 0093). Emitted by the
## module; consumed by any observer.
##
## Everything here announces a fact **already written** — a declaration in the ledger, or a
## prize already paid through `HoldingsApi.apply_prize`. A consumer must never treat one of
## these as a request it can veto: that is ADR 0093's line between an event and a hook.
##
## An *instance*, exactly as `HoldingsEvents` and `NationEvents`: a `RefCounted` cannot emit its
## own signal without an object to emit on, so `ConflictApi` holds one and emits through it, and
## `ConflictApi.events()` is the accessor so a subscriber in another module can reach it.

## A standoff was declared over `node_id` with its PRIZE and its quota. `prize` is the declared
## shape — `ownership`, `recognition` or `tribute` — and is **never computed at resolution**
## (ADR 0085); a consumer that re-derives what is at stake from the sides has re-invented the
## declaration this signal publishes.
##
## **The holder did not move.** The standoff is open, not decided: a `claim` on held ground opens
## one and leaves the holder byte-identical, and declaring the prize changes nothing about that.
signal standoff_declared(
	actor_id: String, node_id: StringName, conflict_id: String, prize: String, quota: int
)

## A standoff closed and its declared prize was PAID. `prize` is the shape that was declared and
## that was paid, which are the same string because the resolution reads the declaration rather
## than computing anything. `holder_id` is the holder as it stands after the payout, and
## `winner_id` the side the verdict named.
##
## This is emitted once per decided standoff. A second resolution refuses `already_resolved`
## rather than announcing a second payment, so a consumer may treat this as "the prize landed"
## and not as "a verdict was offered".
signal standoff_resolved(
	actor_id: String, node_id: StringName, conflict_id: String, prize: String, winner_id: String
)

## A refusal that wrote nothing. Carries the named reason so a panel renders the rule it was
## given rather than inventing one (ADR 0084), and so an action failing is observable rather
## than silent.
##
## **The one signal here that announces something did NOT become true**, and that is the point
## of it. Every other signal announces a fact already written; this one announces that a rule
## fired and the ledger is unchanged. The two are independent facts about one refusal: the
## returned dictionary carries `ok: false`, and this carries WHICH rule refused and ON WHICH NODE.
##
## Emitted from `ConflictApi._refuse`, the single place every refusal on that facade is built,
## so no call site can forget to announce it.
signal conflict_refused(actor_id: String, node_id: StringName, reason: String)