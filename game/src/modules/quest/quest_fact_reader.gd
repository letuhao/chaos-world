class_name QuestFactReader
extends RefCounted

## The **read-only** half of ADR 0113, from this module's side of the seam.
##
## ADR 0113 puts `WorldFactLedger` in `core/world_fact.gd` under
## `actor.module_data["world_facts"]`, with `count(id)`, `has(id, need)` and
## `record(actor, id, amount)`. **This module may only read it.** A quest step
## asks the ledger a question; the world's own systems are what write to it.
## Keeping the read behind one file means the rule "a quest never counts its own
## progress" is enforced by the ABSENCE of a write verb rather than by a comment,
## and it means there is exactly one place to change if the ledger's storage key
## ever moves.
##
## ## Why this file reads the payload instead of calling the class
##
## `core/world_fact.gd` is authored by the core-layer agent in parallel with this
## module, and **it did not exist when this module was built.** A hard reference
## to a symbol that does not resolve is a parse error, and a parse error in one
## file cascades a thousand "Could not resolve class" errors across every
## dependant — it would take the entire test run down, not just this module.
##
## So the reader reads the ledger's stored payload directly, through `Actor`'s own
## `get_module_data` accessor. That is exactly what `WorldFactLedger.count(id)`
## does over the same dictionary, and it holds three properties worth having:
##   - **No hard dependency.** The module parses and runs whether or not the
##     ledger class has landed. When it lands, nothing here changes: the key and
##     the row shape are fixed by ADR 0113, not by the class.
##   - **No cross-unit edge for the arch gate.** No `preload`, no `extends`, no
##     bare typed reference — the module declares `core` as a dependency and has
##     nothing else to declare.
##   - **One place to change.** If the ledger ever stores rows differently, this
##     file is the only thing in the repo that has to know.
##
## ## Reading a ledger that is absent is correct, not convenient
##
## A save written before ADR 0113 has no `world_facts` key at all, and a
## malformed row must not make a quest crash. Both answer 0 — and 0 is the RIGHT
## answer: a ledger that has never heard of a fact holds none of it, so a step
## reports honestly outstanding rather than silently complete. `available()` lets a
## UI distinguish "no progress yet" from "no ledger", which look identical from the
## outside and mean very different things to a player.

## `actor.module_data` key ADR 0113 fixes for the ledger.
const LEDGER_MODULE_KEY := &"world_facts"
## The row shape ADR 0113 fixes: a fact is `{id, count, since}` and nothing else.
const FACT_COUNT_KEY := "count"
## The payload key the rows hang under: `{version, facts: {id: {count, since}}}`.
const FACTS_KEY := "facts"


## How many times `fact` is recorded for `actor`. 0 when the ledger is absent,
## unreadable, or has never heard of the fact.
##
## The lookup is two levels deep: the payload is `{version, facts: {id: {count,
## since}}}`, not `{id: {count}}`. It read the payload's own keys, so it asked
## `ledger.get("<fact id>")` of a dictionary whose only keys are `version` and
## `facts` — every lookup missed, every step reported 0, and no quest could ever
## complete from the world's memory. `available()` two functions below already
## read `ledger.get("facts", ...)`, which is what made the shape unmistakable:
## one function in this file knew the real layout and the other two did not.
static func count(actor: Actor, fact: StringName) -> int:
	if actor == null or fact == &"":
		return 0
	var ledger := _ledger(actor)
	var facts = ledger.get(FACTS_KEY, null)
	if not (facts is Dictionary):
		return 0
	var found = (facts as Dictionary).get(String(fact), null)
	if not (found is Dictionary):
		return 0
	return int((found as Dictionary).get(FACT_COUNT_KEY, 0))


## Whether the ledger holds at least `need` of `fact`. The single question a step
## asks. `need` below 1 is normalized to 1, so a step is never satisfied by a
## ledger that has never heard of its fact.
static func has(actor: Actor, fact: StringName, need: int) -> bool:
	return count(actor, fact) >= maxi(1, need)


## Whether `actor` carries a readable ledger at all — the distinction a UI needs
## between "no progress yet" and "this build has no ledger".
static func available(actor: Actor) -> bool:
	if actor == null:
		return false
	var ledger := _ledger(actor)
	if ledger.is_empty():
		return false
	return ledger.get(FACTS_KEY, null) is Dictionary


# --- Internals -------------------------------------------------------------


## The ledger's stored payload, or an empty dictionary when there is none.
##
## Read straight off `module_data` through `Actor`'s own accessors, so this module
## never reaches past the public API of the actor it is handed.
static func _ledger(actor: Actor) -> Dictionary:
	var pending = actor.get_module_data(LEDGER_MODULE_KEY)
	if pending is Dictionary:
		return pending
	return {}
