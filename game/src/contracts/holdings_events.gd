class_name HoldingsEvents
extends RefCounted

## Signal contract for the `holdings` module (ADR 0097, ADR 0093). Emitted by the module;
## consumed by any observer.
##
## Everything here announces a fact **already written to the ledger**. A consumer must never
## treat one of these as a request it can veto — that is the distinction ADR 0093 draws between
## an event and a hook — and nothing carries a number the caller could not already read from
## `HoldingsApi.state`.
##
## An *instance*, exactly as `DestinyEvents` and `NationEvents`: a `RefCounted` cannot emit
## its own signal without an object to emit on, so the module holds one and emits through it.
## `HoldingsApi` stays a namespace of statics.

## A node was taken by a holder who previously held nothing. **This is not "the land moved
## on"**: an unheld node becoming held is the only case where the holder changes here, and
## `node_id` is a CLAIM over a resource, never a coordinate (ADR 0045).
signal node_claimed(actor_id: String, node_id: StringName, holder_id: String)

## A claim was opened against a node that is ALREADY held. **The holder is unchanged**, and
## that is the whole point (ADR 0085): a claim opens a standoff, it is not a conquest. A
## consumer that renders this as the land changing hands has broken the invariant.
signal node_contested(
	actor_id: String, node_id: StringName, holder_id: String, challenger_id: String
)

## The holder gave the node up. Always permitted for the holder, never a gate, and it does
## not forgive the obligation lines the claim charged.
signal node_released(actor_id: String, node_id: StringName, holder_id: String)

## `periods` of yield accrued into the node's line, and upkeep charged against the holder.
## `periods` is always caller-supplied (DEF-0111): this module has no tick, so this signal is
## the only accrual announcement and there is no ambient one to miss.
signal node_accrued(
	actor_id: String, node_id: StringName, holder_id: String, periods: int, yielded: int
)

## A DECIDED conflict paid its declared prize against `node_id`. `prize` is the declared
## shape — `ownership`, `recognition` or `tribute` — and is never computed at resolution
## (ADR 0085). `holder_id` is empty when the prize was recognition or tribute, which moved no
## holder: a consumer must not read an empty holder as "the node was abandoned".
signal prize_applied(
	actor_id: String, node_id: StringName, prize: String, holder_id: String, winner_id: String
)

## A refusal that wrote nothing. Carries the named reason so a panel renders the rule it was
## given rather than inventing one (ADR 0084), and so an action failing is observable rather
## than silent.
##
## **The one signal here that announces something did NOT become true**, and that is the
## whole point of it rather than an exception to the contract. Every other signal announces a
## fact already written; this one announces that a rule fired and the ledger is unchanged.
## The two are independent facts about one refusal, and a caller needs both: the returned
## dictionary carries `ok: false`, and this signal carries WHICH rule refused and ON WHICH
## NODE. A consumer must therefore not read this as a veto — nothing is undone, and nothing
## needs undoing, because the atomicity guarantee is that a refused verb wrote nothing.
##
## Emitted from `HoldingsApi._refuse`, which is the single place every refusal on that
## facade is built — so no call site can forget to announce, and a panel can never miss one.
signal holding_refused(actor_id: String, node_id: StringName, reason: String)
