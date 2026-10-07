class_name DialogueEvents
extends RefCounted

## Signal contract for the `dialogue` module (ADR 0093, ADR 0269). Emitted by the module;
## consumed by any observer.
##
## Everything here announces a fact **already written to the ledger**: a conversation
## opened, a choice taken, a conversation closed, or a named refusal that wrote nothing.
## A consumer must never treat one as a request it can veto — that is the line ADR 0093
## draws between an event and a hook.
##
## ## Primitives only
##
## No `Resource`, no `Actor`, no authored `Dictionary` crosses this boundary. What
## happened is a fact about an actor's stored conversation row, and everything a consumer
## could want — the current node, the variable store — is readable from
## `DialogueApi.summary(actor)` and `DialogueApi.current(actor)`. Carrying a
## `DialogueDef` would hand a subscriber a live editor handle on shipped content, the same
## rule `BeatSink`'s payload (ADR 0114) and `QuestEvents` state.
##
## ## `shared()`, not a fresh instance per subscriber
##
## A `RefCounted` cannot emit a signal without an object to emit on, so someone holds the
## instance. The house answer for a contract-level bus is a process-wide static
## (`QuestEvents.shared()`), so a mod subscriber names the BUS CLASS and nothing else and
## `_resolve_events_bus` needs no module edge. A fresh instance per lookup would be dead
## on arrival — connected forever, emitted on by nobody — which is the failure
## `QuestEvents` records.

## A conversation opened for `npc_id` at `node_id`.
signal dialogue_started(actor_id: String, npc_id: String, dialog_id: String, node_id: String)

## A choice was TAKEN and the row moved. `node_id` is `""` when the choice ended the
## conversation. Fires after the effect is written and the move is persisted, so a
## consumer reads a state that already exists.
signal dialogue_choice_taken(actor_id: String, choice_id: String, node_id: String)

## A conversation closed. `dialog_id` is the one that was open.
signal dialogue_ended(actor_id: String, dialog_id: String)

## A refusal that wrote nothing, carrying the named reason so a panel renders the rule it
## was given. `choice_id` is `""` on a verb that did not address a choice.
signal dialogue_refused(actor_id: String, reason: String, choice_id: String)

static var _shared: DialogueEvents = null


## The single bus every dialogue publisher and subscriber shares.
static func shared() -> DialogueEvents:
	if _shared == null:
		_shared = DialogueEvents.new()
	return _shared
