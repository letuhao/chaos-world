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

## A consumer answered a decision the npc module asked. `kind` names the question.
signal decision_answered(npc_id: String, kind: StringName, decision: Dictionary)

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
