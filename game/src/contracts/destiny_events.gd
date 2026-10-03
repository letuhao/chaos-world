class_name DestinyEvents
extends RefCounted

## Signal contract for fate and destiny (ADR 0065). Emitted by the destiny
## module; consumed by any observer.
##
## Fate and destiny are **earned**, never chosen and never equipped. There is
## no removal path, so every signal here is an announcement of something that
## has already permanently happened. A consumer must never treat these as a
## request it can veto.
##
## This is an *instance*, not a static class of constants: a `RefCounted` cannot
## emit its own signal without an object to emit on, so the owning module holds
## one `DestinyEvents.new()` and emits through it. `WorldEvents` declares the
## shape of the same idea but has no emitter and no consumer, so it is not a
## working precedent to copy — this one is wired.

## A fate was appended to the ledger for the first time. `source` names the
## system that earned it, so a consumer can react to *how* without re-deriving
## the cause. A replayed earn never re-emits this.
signal fate_earned(actor_id: String, fate_id: StringName, source: String)

## A destiny branch was appended for the first time.
signal destiny_earned(actor_id: String, destiny_id: StringName, source: String)

## A named counter moved. `amount` is the applied delta, `total` the value after
## it. A counter never decreases, so `total` is monotonic.
signal counter_changed(actor_id: String, counter_id: StringName, amount: int, total: int)

## A gate refused access to gated content. This is an observation, never a veto:
## the caller has already been refused and is not waiting on this signal.
signal gate_failed(actor_id: String, reason: String, requirement: Dictionary)
