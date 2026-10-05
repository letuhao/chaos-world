class_name NationEvents
extends RefCounted

## Signal contract for the nation module (ADR 0083, ADR 0085). Emitted by the
## module; consumed by any observer.
##
## A nation is the third institution tier: offices that may be **vacant**, and
## claims over land that are not the land itself. Everything here announces a
## fact that has already been written to the ledger — a consumer must never
## treat one of these as a request it can veto, and nothing here carries a
## number the caller could not already read from `NationApi.state`.
##
## This is an *instance*, exactly as `DestinyEvents` is: a `RefCounted` cannot
## emit its own signal without an object to emit on, so `NationProjection` holds
## one `NationEvents.new()` and emits through it. `NationApi` stays a namespace
## of statics and keeps its facade surface for the verbs rather than for a bus.

## A polity was founded and the actor under it now belongs to it.
signal nation_founded(actor_id: String, nation_id: StringName, founder_id: String)

## The nation split, and both halves paid the declared cost (ADR 0085).
signal nation_schismed(actor_id: String, from_id: StringName, to_id: StringName, standing: int)

## A claim over places was taken. `territory_id` is a CLAIM, never a place: the
## holder is unchanged when a claim is contested, so a panel must never read this
## as "the land moved".
signal territory_claimed(actor_id: String, territory_id: StringName, holder_id: String)

## A claim was given up, lapsed on its hold floor, or ceded by a prize.
signal territory_released(actor_id: String, territory_id: StringName, holder_id: String)

## `periods` elapsed against the ledger at a caller's request. There is no world
## tick in this module (DEF-0111), so this is the only accrual announcement.
signal territory_accrued(actor_id: String, territories: int, periods: int, standing: int)

## The one canonical stance row for an unordered pair moved. `pair_key` is the
## two ids ordered lexicographically, so the same row is read whichever way round
## the pair is written (ADR 0047, extended by ADR 0085).
signal stance_changed(actor_id: String, pair_key: String, other_id: StringName, verb: String)

## A standoff was declared with its PRIZE. `mode` changes the quota and the prize
## shape only; the prize itself is never computed at resolution.
signal war_declared(actor_id: String, standoff_id: String, other_id: StringName, mode: String)

## A standoff closed. `outcome` is `resolved`, `withdrawal` or `forfeit`, and a
## `withdrawal` has moved NO territory by construction.
signal conflict_resolved(actor_id: String, standoff_id: String, winner_id: String, outcome: String)

## An office is vacant. This is ADR 0083's second state — the seat EXISTS and its
## value is absent — and it is announced rather than silently represented as `0`.
signal office_vacated(actor_id: String, office_id: StringName, nation_id: StringName)

## An office seat changed hands, including from `""` to a holder and back.
signal office_filled(
	actor_id: String, office_id: StringName, holder_id: String, nation_id: StringName
)
