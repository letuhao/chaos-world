class_name NpcEvents
extends RefCounted

## Typed event contract for the `npc` module. The observation half of the seam: a
## consumer subscribes to these without the npc module naming it (ADR 0076).
##
## **Every signal here announces what already happened.** None is a request and none
## may be vetoed. A subscriber that reacts to `stage_advanced` cannot stop the stage
## from advancing, which is what keeps story progression out of a vote.
##
## Shaped like `world_events.gd` and `destiny_events.gd`: primitives only, one fact per
## signal, and `source` naming the calling system so a consumer can filter its own.

## A tracked npc entered the roster for the first time. `tier` is the authored band.
signal npc_tracked(npc_id: String, tier: StringName)

## A transient npc was minted for a room. It has no roster entry and leaves with it.
##
## ## The one signal on this contract with no subscriber (BL-0797)
##
## `NpcBoot._install_event_seams` connects the other five. **This one is deliberately not
## connected**, and the reservation in `tests/modules/npc/test_npc_event_contract.gd` says
## why: an untracked npc leaves no roster entry by ADR 0092 and `NpcApi.presence_here`
## already reports every live body, tracked or not — so a log of this signal would be a
## strictly worse copy of that read model rather than the only place a fact lives.
##
## **The declaration stays and the producer stays.** BL-0797 asked for a real consumer or a
## recommendation to delete the signal; no real consumer was found and none was invented.
## The owner has not ruled on deletion, so this is the one signal where the honest answer
## is "there is nothing here yet" rather than "deleted" — the difference from
## `decision_answered` below, whose product ruling is closed. What would retire it: a
## consumer that must REACT to a drift existing (a room roster that has to notice someone
## left without re-reading the registry), which nothing does today.
signal npc_transient(npc_id: String)

## An npc moved to a later authored stage. `source` names what drove it, never a number.
signal stage_advanced(npc_id: String, stage_id: StringName, source: String)

## An npc's relationship changed. `cause` is a `SocialCauseDef` id, never a raw delta,
## so a consumer reads *why* without re-deriving it (ADR 0076).
signal bond_changed(npc_id: String, cause_id: StringName)

## An npc's presence changed: unknown, known, present or retired.
signal presence_changed(npc_id: String, presence: StringName)

## A tracked npc was restored from a save, carrying its stage and tier.
signal npc_restored(npc_id: String, tier: StringName, stage_id: StringName, tracked: bool)

## ## What is NOT here, and why it is not coming back for free
##
## `decision_answered(npc_id, kind, decision)` was removed (audit F2, BL-0793). It was the
## seam an original design proposed for "an npc asks the player something and the player
## answers" — a concept that was **deliberately rejected** as ceremony with zero
## implementors, and the signal outlived the rejection. No production code ever emitted it
## and no subscriber ever connected, so every consumer reading this contract went looking
## for a decision system that does not exist.
##
## ADR 0093 line 28 refuses `NpcDecision` and states the trigger that would un-refuse it:
## "a second consumer must *ask a question and wait for an answer* rather than evaluate
## one". No such consumer exists. BL-0745 (`shared_brotherhood`) is the one feature that
## would need it, and it is **blocked on a product ruling only the repo owner can make** —
## so this gap must not be wired from under that decision.
##
## `tests/modules/npc/test_npc_event_contract.gd` now fails the moment a signal is declared
## here that production code cannot emit, so the next agent to add one is caught on the
## spot rather than by an audit wave later.

## ## The one bus, and why it lives HERE rather than behind `NpcApi.events()`
##
## `NpcApi.events()` is still how a SUBSCRIBER reaches the contract — the accessor ADR 0093
## names stays the public face, unchanged. But `bond_changed` is announced by `social/`,
## which owns the ledger that a bond is, and `social/` declares `contracts` and `core` and
## NOT `npc/`. A bus held only on the facade would therefore be unreachable from the one
## module with something to announce, which is precisely how a declared signal becomes a
## signal nobody emits — the state ADR 0093 describes and does not excuse.
##
## `contracts/` is the leaf layer (`LAYER_DEPS` in `tools/arch/rules.py`), so a static here
## is a legal home for a shared instance and no dependency is invented to carry it.
static var _shared: NpcEvents = null


## The single bus every npc-event publisher and subscriber shares. Stable across calls, so
## a subscriber that connected once is still connected the next time this is asked for.
static func shared() -> NpcEvents:
	if _shared == null:
		_shared = NpcEvents.new()
	return _shared
