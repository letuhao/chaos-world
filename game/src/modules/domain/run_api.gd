class_name DomainRunApi
extends RefCounted

## The `domain` module's SECOND facade, and it exists because `api.gd` hit its cap
## (ADR 0230's run, ADR 0229's band).
##
## ## Why a second facade file rather than four more verbs on `api.gd`
##
## `rules.MAX_FACADE_PUBLIC_METHODS` is 12 and `api.gd` was at exactly 12 before the run
## landed: `map_summary`, `templates`, `generate_and_enter`, `rooms`, `room`,
## `environment_zones`, `population`, `discovered`, `summary`, `enter`, `leave`,
## `visit_room`. The band added four — `band`, `record_kill`, `exit_gate`,
## `abandon_band` — which is the breach `test_domain_api.gd:62` and
## `test_domain_fixture_reads.gd:380` both assert and `tools arch` both enforce.
##
## `api.gd`'s own docblock already names the answer it wants when this happens: *"When a
## UI need arrives, publish the read data inside an existing read model rather than
## appending a verb"* — and its module banner names the other one: *"`socket` set the
## precedent: a feature that outgrows a neighbour owns its own facade rather than growing
## one that is capped."* This is that: the RUN is a separable concern with its own
## lifecycle (a fight either ends or it does not), so it gets its own interface rather
## than four verbs bolted onto the map's.
##
## ## What this does NOT do, and the rule it does not break
##
## **The facade-only rule is untouched.** `rules.BARE_REF_UNITS`/`enforce.py` permit a
## module to reach another module ONLY through `modules/<dep>/api.gd`, and this file is
## INSIDE `modules/domain/` — so it is `domain` reaching `domain`, one module reading its
## own internals, which is not a cross-module edge at all. No `registry.json` change, no
## new module, no `ui/` entry: `domain` is still not in `rules.UI_MODULES` and this file
## does not make it reachable from `ui/`.
##
## ## Who may call it
##
## `app/` — the composition root, and per ADR 0236 the only layer permitted to drive a
## run — plus the tests that prove the run. `DomainFight` calls all four verbs; nothing
## else in `game/src` does, which is the point: a run advances through a decided verdict
## and nothing else (ADR 0229, ADR 0236).
##
## ## And the READ half is still on `api.gd`
##
## `DomainApi.summary(actor)["run"]` keeps publishing the whole band, because a screen
## and the headless driver read it there and have since ADR 0229. This file adds the verbs
## that summary cannot express: an answer that is a refusal, and the ONE write.

## The `domain` module's state key. Reached through `DomainApi` rather than restated, so
## a key that moved in one place could not be half-moved here.
const MODULE_KEY := DomainRun.MODULE_KEY

## Nobody to run.
const ERR_NO_ACTOR := DomainApi.ERR_NO_ACTOR


## The actor's band as `DomainRun.view` publishes it, or `{}` when no run is in flight.
## `{}` rather than a blank run, because "no band" and "a band with nothing left in it"
## are different facts and a screen must be able to tell them apart.
##
## A one-line forward onto `DomainApi._band` rather than a re-derivation: the two spellings
## must answer the same dictionary or a caller would have two views of one run.
##
## The `_` IS the point, and it is not a leak of a private: `api.gd` is at
## `rules.MAX_FACADE_PUBLIC_METHODS`, so the four band verbs are declared private there
## and THIS file is the only way a caller reaches them (`api.gd`'s own section header says
## so). Naming the public spelling here would not compile — `DomainApi` declares `_band`,
## not `band` — and a compile failure in this file takes `app/domain_fight.gd` and every
## suite that drives a run with it.
static func band(actor: Actor) -> Dictionary:
	return DomainApi._band(actor)


## Record that `boss_id` fell in this actor's band, and open the next door.
##
## THE ONE VERB THAT ADVANCES A RUN. `DomainRun.record_kill` is its only writer of
## `open_index`, and nothing in `domain/`, `combat/` or `ui/` can open a door by any
## other route — which is what makes ADR 0229's "a kill is the only thing that opens the
## next door" a structural property rather than a convention somebody can route around.
##
## `app/` calls this with the id it RESOLVED from the fight's own verdict. `domain` never
## derives who died from a health number, because damage arithmetic is not something a
## traversal layer may see (ADR 0228's own rejection of a `kill_inhabitant` verb).
static func record_kill(actor: Actor, boss_id: String, killer_id: String = "") -> Dictionary:
	return DomainApi._record_kill(actor, boss_id, killer_id)


## Whether the exit is claimable, and why not when it is not (ADR 0229's exit gate).
##
## **Clearing the band is the gate; the EXIT is not trapped.** This is a refusal of the
## CLAIM, never of the leaving: `leave` stays free and costs nothing, so a player who
## cannot retreat cannot make a commitment, and commitment is what the anchor measures.
static func exit_gate(actor: Actor) -> Dictionary:
	return DomainApi._exit_gate(actor)


## Abandon this actor's band: the run stops and nothing is owed (ADR 0236). Idempotent, so
## a defeat that also fires the combat-exit purge does not hand the second caller a failure
## for the state it already has.
static func abandon_band(actor: Actor, cause: String = "defeated") -> Dictionary:
	return DomainApi._abandon_band(actor, cause)
