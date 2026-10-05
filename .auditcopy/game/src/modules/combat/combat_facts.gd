class_name CombatFacts
extends RefCounted

## The world facts `combat` is the OWNER of, and the only place this module writes
## `core`'s fact ledger (ADR 0137).
##
## ## Why a module writes the ledger at all
##
## ADR 0114 routes a beat through one director in `app/`, and
## `event/EventBeatWriter` is the production writer that lives inside a module rather
## than in the composition root. ADR 0137 decides that a fact whose real owner already
## exists is recorded **by the owning module when the action succeeds** — one ledger,
## one writer set, no new subsystem.
##
## ## These are never ambient, and never will be
##
## `what_the_rotation_cost.tres` asks for three duels won and a spared opponent, and a
## world roster that reported them would be the quest's demand echoed back (ADR 0137).
## `tests/app/test_world_ambient_facts.gd::test_a_fact_the_world_never_reports_is_still_outstanding`
## holds that a player's duels are **not** ambient, and these two ids are why that test
## is true rather than merely written.
##
## ## Each id is a same-file `const` named AT the call, and that is not a style choice
##
## `tools gate_reach.py` reads a code-owned producer out of `const NAME := &"id"` in
## the SAME file as the `WorldFact.record(...)` call, and only when the bare const NAME
## is the id argument. Passing `CombatFacts.FACT_DUELS_WON` is a member expression it
## cannot resolve, and the gate would be reported dead while the game supplies it.

## This actor won a duel: the blow landed and the opponent did not get up.
const FACT_DUELS_WON := &"duels_won"

## This actor let an opponent walk: the duel was ended without a killing blow.
const FACT_THIRD_MAN_SPARED := &"third_man_spared"


## Record one duel won by `actor`. The one write path for [constant FACT_DUELS_WON].
static func record_duel_won(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	return WorldFact.record(actor, FACT_DUELS_WON, 1)


## Record that `actor` spared an opponent. The one write path for
## [constant FACT_THIRD_MAN_SPARED].
static func record_spared(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	return WorldFact.record(actor, FACT_THIRD_MAN_SPARED, 1)
