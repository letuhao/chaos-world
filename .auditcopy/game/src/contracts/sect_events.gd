class_name SectEvents
extends RefCounted

## Signal contract for a sworn sect (ADR 0083/0084). Emitted by the sect module;
## consumed by any observer.
##
## ## Every signal here is an announcement, never a veto
##
## A sect grants **recognition, access and transmission, and never power**
## (ADR 0084). A claim that already happened is being described, so a consumer
## may react — a codex entry, an audio cue, a quest beat — and may not block.
## By the time a signal fires the ledger has already been written and the stat
## projection rebuilt, so a consumer that returns `false` would be lying about
## something that is already true. The signals that report a refusal exist so a
## panel can say why a button was disabled; they arrive after the refusal, never
## in place of one.
##
## This is an *instance*, not a static class of constants: a `RefCounted` cannot
## emit its own signal without an object to emit on, so the owning module holds
## one `SectEvents.new()` on its projection and emits through it — the same
## wiring `DestinyEvents` has, which is the only working precedent in
## `contracts/` for a bus with a real emitter.

## A member's claim changed: which sect they are sworn to, which position they
## hold, or what standing they carry. `kind` names the write (`join`, `leave`,
## `promote`, `standing`, `expel`) so a consumer can react to *how* without
## re-deriving the cause from the numbers.
signal claim_changed(actor_id: String, sect_id: StringName, position_id: StringName, kind: String)

## The claim left one sect entirely, or arrived at one. `reason` is the facade's
## authored refusal string when the call was refused (`not_a_member` for a leave
## that had nothing to leave), and `""` on a change that landed.
signal membership_changed(actor_id: String, sect_id: StringName, joined: bool, reason: String)

## Standing moved by `amount`, leaving `total`. Standing is earned and can fall
## (ADR 0064), so `amount` is signed and only `total` is monotonic-in-perception
## rather than in fact. Publishing the applied delta is what makes the write
## observable: a refused move publishes nothing at all (ADR 0084).
signal standing_changed(actor_id: String, sect_id: StringName, amount: int, total: int)

## Gated content refused to open, or a verb was refused. `reason` is an authored
## constant, never free text, so a panel renders a reason it did not invent. This
## is an observation of a decision already taken, never a request to take it back.
signal gate_refused(actor_id: String, reason: String, requirement: Dictionary)
