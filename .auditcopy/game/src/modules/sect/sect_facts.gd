class_name SectFacts
extends RefCounted

## The world facts `sect` is the OWNER of, and the only place this module writes
## `core`'s fact ledger (ADR 0137).
##
## ## Why a module writes the ledger at all
##
## ADR 0114 routes a beat through one director in `app/`, and
## `event/EventBeatWriter` is the production writer that lives inside a module rather
## than in the composition root. ADR 0137 decides that a fact whose real owner already
## exists is recorded **by the owning module when the action succeeds** — one ledger,
## one writer set, no new subsystem. A fourth dispatcher to route two ids through would
## be ADR 0066's quiet lie with a queue in front of it.
##
## ## These are never ambient, and never will be
##
## A world pulse that reported "you held the post" is the quest's demand echoed back
## (ADR 0137). These two ids are produced by the act that earns them and by nothing
## else, which is what keeps
## `tests/app/test_world_ambient_facts.gd::test_a_fact_the_world_never_reports_is_still_outstanding`
## honest about a player's duels.
##
## ## Each id is a same-file `const` named AT the call, and that is not a style choice
##
## `tools gate_reach.py` reads a code-owned producer out of `const NAME := &"id"` in
## the SAME file as the `WorldFact.record(...)` call, and only when the bare const NAME
## is the id argument. Passing `SectFacts.FACT_POST_HELD` is a member expression it
## cannot resolve, and the gate would be reported dead while the game supplies it — a
## false red, which is worse than a false green because it sends the next agent to
## author a producer that already exists.
##
## The one-call-per-fact shape below is also why this file exists at all: it is the
## smallest unit that can hold the const and the call together.

## An office of this sect was HELD by this actor.
##
## Written on the promotion that actually SEATS somebody, and never on a
## re-promotion into the seat already held. "You held a post" is a transition, and a
## monotone ledger that recorded the no-op would answer "how many posts have you held"
## with "how many times were you told again".
const FACT_POST_HELD := &"sect_post_held"

## A sworn term of this sect was DISCHARGED — brought to zero, not merely reduced.
const FACT_OATHS_DISCHARGED := &"oaths_discharged"


## Record that `actor` took an office. The one write path for
## [constant FACT_POST_HELD].
static func record_post_held(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	return WorldFact.record(actor, FACT_POST_HELD, 1)


## Record `amount` sworn terms discharged in full.
##
## `amount` is what the caller ACTUALLY cleared and is required, never defaulted to a
## constant: a discharge that brought one line to zero and left two open owes the world
## exactly one oath, and a caller that reported a fixed number would put a claim in the
## ledger that no line in it supports.
static func record_oaths_discharged(actor: Actor, amount: int) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if amount < 1:
		return {"ok": false, "reason": "no_amount"}
	return WorldFact.record(actor, FACT_OATHS_DISCHARGED, amount)
