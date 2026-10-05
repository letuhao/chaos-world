class_name ClanFacts
extends RefCounted

## The world facts `clan` is the OWNER of, and the only place this module writes
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
## ## This is never ambient, and never will be
##
## A world roster that reported "you were entered in the household register" is the
## quest's demand echoed back (ADR 0137). The id is produced by the registration that
## earned it and by nothing else.
##
## ## The id is a same-file `const` named AT the call, and that is not a style choice
##
## `tools gate_reach.py` reads a code-owned producer out of `const NAME := &"id"` in
## the SAME file as the `WorldFact.record(...)` call, and only when the bare const NAME
## is the id argument. Passing `ClanFacts.FACT_HEIR_REGISTERED` is a member expression
## it cannot resolve, and the gate would be reported dead while the game supplies it.

## This member's name is entered in their household's register as its heir.
const FACT_HEIR_REGISTERED := &"household_heir_registered"


## Record that `actor` was entered in the register. The one write path for
## [constant FACT_HEIR_REGISTERED], and it is called only once a registration has
## actually landed — a refusal reaches it never.
static func record_heir_registered(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	return WorldFact.record(actor, FACT_HEIR_REGISTERED, 1)
